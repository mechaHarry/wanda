import AppKit
import SwiftUI

struct TerminalWindowView: View {
    private static let terminalCellSize = CGSize(width: 9, height: 18)

    @StateObject private var viewModel = TerminalViewModel()
    @StateObject private var windowGeometry = TerminalWindowGeometryController()

    var body: some View {
        GeometryReader { geometry in
            let layout = terminalInputLayout(for: geometry.size)

            ZStack(alignment: .topLeading) {
                TerminalMetalViewRepresentable(
                    snapshot: viewModel.snapshot,
                    onFramePresented: viewModel.framePresented(at:)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TerminalSelectionOverlay(
                    selection: viewModel.selection,
                    snapshot: viewModel.snapshot,
                    viewSize: geometry.size
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TerminalInputView(
                    layout: layout,
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
                windowGeometry.saveCurrentWindowFrame()
                viewModel.stop()
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .background {
            WindowAccessor { window in
                windowGeometry.observe(window: window)
            }
        }
    }

    private func resizeTerminal(to size: CGSize) {
        let columns = max(1, Int(size.width / Self.terminalCellSize.width))
        let rows = max(1, Int(size.height / Self.terminalCellSize.height))
        viewModel.resize(columns: columns, rows: rows)
    }

    private func terminalInputLayout(for size: CGSize) -> TerminalInputLayout {
        TerminalInputLayout(
            columns: max(1, Int(size.width / Self.terminalCellSize.width)),
            rows: max(1, Int(size.height / Self.terminalCellSize.height)),
            viewSize: size
        )
    }
}

private struct TerminalSelectionOverlay: View {
    var selection: TerminalSelection?
    var snapshot: TerminalRendererSnapshot?
    var viewSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let selection, let snapshot {
                let cellSize = effectiveCellSize(for: snapshot)

                ForEach(Array(selection.rowRanges(columns: snapshot.columns, rows: snapshot.rows).enumerated()), id: \.offset) { _, range in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.32))
                        .frame(
                            width: CGFloat(range.endColumn - range.startColumn + 1) * cellSize.width,
                            height: cellSize.height
                        )
                        .offset(
                            x: CGFloat(range.startColumn) * cellSize.width,
                            y: CGFloat(range.row) * cellSize.height
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func effectiveCellSize(for snapshot: TerminalRendererSnapshot) -> CGSize {
        guard snapshot.columns > 0, snapshot.rows > 0 else {
            return CGSize(width: 1, height: 1)
        }

        return CGSize(
            width: viewSize.width / CGFloat(snapshot.columns),
            height: viewSize.height / CGFloat(snapshot.rows)
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
